class_name SimConstants
extends RefCounted

## The single data-driven config for the history simulation
## (gdd-history-simulation.md §7.8 consolidated constants table). Per the
## build handoff §Stage 4: "Every constant comes from §7.8 — implement them as
## one data-driven config resource, not scattered literals" so the balance
## pass (history-sim §17) can retune without code changes.
##
## All values are [PROVISIONAL] pending that one tuning pass. A SimConstants
## instance is constructed once per generation run and threaded through the
## sim; tests may override individual fields before running.

# --- Time (§3, §4) ----------------------------------------------------------
var tick_years: int = 25
# N_TICKS comes from SettingParameters.history_ticks() (80/160/240).

# --- Expansion (§7.2) -------------------------------------------------------
var expansion_G: float = 4.0          # global growth constant (hexes/tick)
var expansion_N0: float = 30.0        # half-saturation size (hexes)
var expansion_alpha_base: float = 1.0 # α = 1.0 + culture.size_exponent_bias
var a_peak_ticks: int = 8             # ascendancy/age peak (200 yr)
var ruler_expansion_strong: float = 1.1
var ruler_expansion_weak: float = 0.9

# --- Border contest (§7.3) --------------------------------------------------
var power_exponent: float = 0.3
var power_clamp_min: float = 0.7
var power_clamp_max: float = 1.5
var home_capital: float = 1.75        # home_factor: capital hex
var home_near: float = 1.4            # ≤2 hexes from capital
var home_mid: float = 1.2             # ≤4 hexes
var home_far: float = 1.0             # else
var contest_attrition: float = 0.005  # per failed contest
var contest_attrition_cap: float = 0.05 # per tick per polity

# --- Stability / collapse (§7.5) --------------------------------------------
var collapse_base: float = 0.01
var collapse_risk_min: float = 0.0
var collapse_risk_max: float = 0.35
var tier_risk_mult: float = 1.35      # f_size = TIER_RISK_MULT ^ max(0, tier-2)
var tier_risk_cohesion_floor: int = 2 # County — risk compounds above this tier
var f_age_floor: float = 0.4          # young-polity ramp start
var f_age_slope: float = 0.15         # per A_PEAK past the peak
var f_age_cap: float = 2.5
var reign_ticks: int = 2              # ruler-quality redraw period (~50 yr)
var ruler_risk_strong: float = 0.7
var ruler_risk_average: float = 1.0
var ruler_risk_weak: float = 1.3
var ruler_quality_strong_p: float = 0.25
var ruler_quality_weak_p: float = 0.25  # remainder is average

# --- Economy / garrison (§7.5.1) --------------------------------------------
var garrison_rate_civilized: int = 2  # gp/family
var garrison_rate_borderlands: int = 3
var garrison_rate_wilderness: int = 4
var frontier_rival_bonus: float = 0.5
var frontier_distance_bonus: float = 0.25
var frontier_distance_threshold: int = 6  # capital distance > this
var frontier_mult_cap: float = 1.75
var target_coverage_base: float = 0.7
var target_coverage_military_weight: float = 0.6
var target_coverage_ruler_delta: float = 0.1
var target_coverage_min: float = 0.5
var target_coverage_max: float = 1.2
var overext_w1: float = 1.0           # under-garrison weight
var overext_w2: float = 2.0           # insolvency weight
var overext_cap: float = 3.0
var income_services_per_family: int = 4
var income_taxes_per_family: int = 2
var overhead_per_family: int = 3      # liturgies + maintenance + tithes
var min_garrison_per_family: int = 2  # RAW 2gp floor (axioms line 226)

# --- Collapse outcomes / severity (§7.6) ------------------------------------
var severity_tier_weight: float = 0.3
var severity_overext_weight: float = 0.4
var severity_proneness_weight: float = 0.6
var severity_temperament_weight: float = 0.1
var severity_band_rump: float = 0.50  # S < this → rump
var severity_band_shatter: float = 0.85 # rump ≤ S < this → shatter; ≥ → depopulate
var shatter_vassal_gate: int = 2      # need vassals ≥ this or tier ≥ Duchy
var beastman_delay_ticks: int = 2
var beastman_fill_per_tick: float = 0.25  # × density per empty hex

# --- Fading (§7.7) ----------------------------------------------------------
var fade_rate: float = 0.985          # per tick after onset
var fade_onset_tier: int = 3          # Duchy — onset requires tier ≥ this

# --- War escalation (§7.3.1) ------------------------------------------------
var war_threshold: int = 3            # contested hexes triggering escalation
var war_base: float = 0.10
var war_opposed_alignment_mult: float = 1.5
var war_atk_aggression_base: float = 0.5  # strength = (0.5 + aggression) × ...
var war_def_defense_base: float = 0.5
var ruler_war_strong: float = 1.15
var ruler_war_weak: float = 0.85
var multi_war_factor: float = 0.8     # 0.8 ^ (extra simultaneous wars)
var war_margin_jitter: float = 0.15
var war_band_border: float = 0.50     # ≥ this → border victory
var war_band_decisive: float = 0.65   # ≥ this → decisive
var war_band_crushing: float = 0.80   # ≥ this (+ capital reach) → crushing
var capital_reach: int = 4
var svg_vassalize_max: float = 0.35   # ≤ → wholesale vassalization
var svg_annex_min: float = 0.65       # ≥ → annexation
var pillage_aggression_gate: float = 0.7
var pillage_svg_gate: float = 0.3
var pillage_chance: float = 0.5
var pillage_pop_loss: float = 0.20    # −20% front-region pop
var pillage_income_credit: float = 0.5
var war_shock_loser: float = 0.02
var war_shock_winner: float = 0.005

# --- Vassalage / secession (§7.4) -------------------------------------------
var core_max: int = 3                 # directly-held core hexes
var vassal_size_principality: int = 3 # tier ≤ Principality
var vassal_size_kingdom: int = 4
var vassal_size_empire: int = 6
var base_secede: float = 0.05
var liege_weakness_risk: float = 0.15 # collapse_risk above which liege is "weak"

# --- Substrate / demography (§6) --------------------------------------------
var diffuse_rate: float = 0.02
var edge_damp_open: float = 1.0
var edge_damp_rough: float = 0.7      # forest / hills
var edge_damp_barrier: float = 0.25   # mountain or major-river crossing
var edge_damp_sea: float = 0.1
var assimilation_step: float = 0.5
var pop_growth: float = 0.10          # logistic rate/tick
var settle_start_families: int = 500
var cap_wilderness: int = 2000        # 24-mile hex caps (16× 6-mile limits)
var cap_borderlands: int = 4000
var cap_civilized: int = 12480
var urban_fraction: float = 0.10      # of realm pop
var urban_capital_share: float = 0.20 # of the urban allocation
var minority_floor: float = 0.001     # SettingParameters.minority_weight_floor default
# Smallest urban settlement that "counts" — RAW dissolution floor (a settlement
# below 75 urban families dissolves, axioms:686-689). Used as the §6 urban-
# emergence trigger; Layer 6 (§9.1) assigns the actual market class.
var settlement_min_urban_families: int = 75

# --- Classification advancement (limits-of-growth, RAW axioms:165-176) -------
# A 24-mile hex (= 16 6-mile hexes) advances when it FILLS its current class
# (to_borderlands: every 6-mile hex at wilderness max 125 = 2,000/24-mi hex;
# to_civilized: every 6-mile hex at borderlands max 250 = 4,000/24-mi hex).
# Logistic growth approaches the cap asymptotically, so the sim triggers
# advancement at this fraction of the current class cap (the hex is "full").
# The RAW urban-settlement / proximity gates are refined at Layer 6 (§9.6).
var classification_advance_fraction: float = 0.90

# --- Migration (§8) ---------------------------------------------------------
var migrant_fraction: float = 0.30
var migration_pressure_base: float = 0.3
var migration_pressure_min: float = 0.05
var migration_pressure_max: float = 0.6
var migration_dest_min_hexes: int = 3   # ≥ contiguous unclaimed
var migration_dest_terrain_mult: float = 1.15
var migration_speed: int = 10           # hexes/tick

# --- Demihuman arc (§9) -----------------------------------------------------
var epoch_bias_max: float = 3.0
var epoch_bias_start_frac: float = 0.375 # × N_TICKS
var epoch_bias_full_frac: float = 0.75   # × N_TICKS

# --- Replay (§15) -----------------------------------------------------------
var replay_cadence: int = 4           # ticks between frames

# --- Conquest substrate (§4.1 catalog) --------------------------------------
var terrain_mult_seed: float = 1.5    # seed_biomes
var terrain_mult_secondary: float = 1.15
var terrain_mult_neutral: float = 1.0
var terrain_mult_avoided: float = 0.5

# --- Handoff morale gate (§10, §12) -----------------------------------------
var conversion_morale_recent_ticks: int = 2  # conquered ≤ this ago
var conversion_morale_svg_gate: float = 0.5


## VASSAL_SIZE for a realm at the given tier_index (§7.4 tier-scaled).
func vassal_size_for_tier(tier_index: int) -> int:
	if tier_index >= 6:        # Empire
		return vassal_size_empire
	if tier_index >= 5:        # Kingdom
		return vassal_size_kingdom
	return vassal_size_principality  # ≤ Principality


## Garrison gp/family base rate for a territory class.
func garrison_rate_for(territory_class: String) -> int:
	match territory_class:
		"civilized":
			return garrison_rate_civilized
		"borderlands":
			return garrison_rate_borderlands
	return garrison_rate_wilderness


## 24-mile family cap for a territory class (§6).
func cap_for(territory_class: String) -> int:
	match territory_class:
		"civilized":
			return cap_civilized
		"borderlands":
			return cap_borderlands
	return cap_wilderness
