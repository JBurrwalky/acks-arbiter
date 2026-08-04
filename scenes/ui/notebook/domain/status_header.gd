extends PanelContainer

## DomainStatusHeader — fixed slim summary banner above the Domain tab's
## sub-tab strip. Visible across all nine sub-tabs per `gdd-domain-tab.md` §5.
##
## Two compact rows:
##   1. Identity: name · classification · hex count · population · morale band
##   2. Operational: stronghold (val/min) · garrison (gp/fam) · treasury (gp)
##
## Phase 2 implementation surfaces RAW-correct numbers consumed by the Phase
## 0/1 resolvers; pillage / chaotic-tint / multi-domain affordances are
## deferred to Phase 8 / Phase 10.


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _row_identity: Label = null
var _row_operational: Label = null
# Phase 11C: succession-pending banner. Hidden when lifecycle_state != succession_pending.
var _row_succession: RichTextLabel = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 60)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)
	_row_identity = Label.new()
	_row_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_identity.text = "No domain selected"
	vbox.add_child(_row_identity)
	_row_operational = Label.new()
	_row_operational.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_operational.text = ""
	vbox.add_child(_row_operational)
	_row_succession = RichTextLabel.new()
	_row_succession.bbcode_enabled = true
	_row_succession.fit_content = true
	_row_succession.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_succession.visible = false
	vbox.add_child(_row_succession)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Render the header from a domain row. [param domain] is the dict returned by
## `CampaignRepository.get_domain`; pass an empty dict to display the
## pre-domain prompt.
func display(domain: Dictionary) -> void:
	if domain.is_empty():
		_row_identity.text = "No domain yet  ·  See Overview tab for acquisition guidance"
		_row_operational.text = ""
		if _row_succession != null:
			_row_succession.visible = false
		return
	var name := String(domain.get("name", "Untitled Domain"))
	if name.is_empty():
		name = "Untitled Domain"
	var territory := String(domain.get("territory_type", "wilderness")).capitalize()
	# Migration 127 (Phase 11D.1): "Chaotic" badge describes ALIGNMENT (the
	# `alignment` column), not domain_style. A clanhold-style + lawful domain
	# does not earn the "Chaotic" badge here; alignment-vs-religion morale
	# penalties + religion-conversion banners are the alignment-axis surfaces.
	if String(domain.get("alignment", "neutral")) == "chaotic":
		territory += " · Chaotic"
	if String(domain.get("domain_style", "civilized")) == "clanhold":
		territory += " · Clanhold"
	var domain_id := String(domain.get("id", ""))
	var hex_count: int = CampaignRepository.get_domain_hexes(domain_id).size()
	var peasants: int = int(domain.get("peasant_families", 0))
	var morale: int = int(domain.get("morale", 0))
	var morale_tier: String = DomainMoraleResolver.morale_tier(morale)
	_row_identity.text = "%s  ·  %s  ·  %d hex%s  ·  %s fam · %s (%+d)" % [
		name, territory, hex_count,
		"" if hex_count == 1 else "es",
		_format_count(peasants),
		morale_tier, morale,
	]
	# Stronghold / garrison / treasury status.
	var territory_type := String(domain.get("territory_type", "wilderness"))
	var stronghold_value_cp := StrongholdRepository.get_stronghold_value_for_domain(domain_id)
	# Sufficiency uses the effective hex count (owned + intervening for
	# noncontiguous domains) per RAW §noncontiguous_domains L95-98; equals
	# `hex_count` when the domain is contiguous.
	var sufficiency_hex_count: int = StrongholdRepository.get_effective_hex_count_for_domain(domain_id)
	var stronghold_minimum_cp := StrongholdRepository.classification_minimum_cp(
		territory_type, sufficiency_hex_count)
	var stronghold_glyph := _sufficiency_glyph(stronghold_value_cp, stronghold_minimum_cp)
	var garrison_per_fam_gp: int = _garrison_per_family(domain)
	var garrison_min_gp: int = _garrison_min_per_family(territory_type)
	var garrison_glyph := "✓" if garrison_per_fam_gp >= garrison_min_gp else "!"
	var treasury_cp: int = int(domain.get("treasury_cp", 0))
	# All three money values are cp and render through Currency.format_cost —
	# the ONE canonical formatter (conventions §127). Until 2026-07-31 they went
	# through `_format_count`, which printed raw copper as though it were gold on
	# the banner pinned above all nine domain sub-tabs: a 5,000 gp treasury read
	# "500,000" while the Treasury sub-tab one click away correctly read "5,000 gp".
	_row_operational.text = "Stronghold: %s/%s %s   Garrison: %dgp/fam %s   Treasury: %s" % [
		Currency.format_cost(stronghold_value_cp), Currency.format_cost(stronghold_minimum_cp),
		stronghold_glyph,
		garrison_per_fam_gp, garrison_glyph,
		Currency.format_cost(treasury_cp),
	]
	# Phase 11C: succession-pending banner. Shown only when the row's
	# lifecycle_state is in the succession-pending state; the actual heir
	# picker + Confirm flow lives on the Overview sub-tab's Domain
	# Management card.
	if _row_succession != null:
		var state: String = String(domain.get("lifecycle_state", "active"))
		if state == "succession_pending":
			var grace_until: int = int(domain.get("succession_pending_until_day", 0))
			var heir_id: String = String(domain.get("designated_heir_character_id", ""))
			var heir_summary: String = (
				"[color=#f0c060]heir designated: %s[/color]" % heir_id
				if not heir_id.is_empty()
				else "[color=#e08070]no heir designated[/color]")
			_row_succession.text = (
				"[b][color=#e08070]⚠ Succession pending[/color][/b]  ·  "
				+ "%s  ·  grace until day %d  ·  use Overview > Domain Management to designate or confirm an heir"
			) % [heir_summary, grace_until]
			_row_succession.visible = true
		else:
			_row_succession.visible = false


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Thousands separator for NON-MONEY counts only (peasant families). Money goes
## through Currency.format_cost. Handles arbitrarily large values — the previous
## single-group form `"%d,%03d" % [n / 1000, n % 1000]` rendered 3,200,000 as
## "3200,000".
static func _format_count(n: int) -> String:
	var negative := n < 0
	var digits := str(absi(n))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if negative else out


## RAW §insufficient_stronghold: ✓ at or above minimum, ½ at >= 1/2, ¼ at >= 1/4,
## ! below that (base morale -1 / -2 / -3 respectively). Both arguments are cp;
## the comparison is unit-agnostic so long as they agree, but the parameters were
## named `_gp` until 2026-07-31 while every caller passed cp (conventions §127).
static func _sufficiency_glyph(value_cp: int, minimum_cp: int) -> String:
	if minimum_cp <= 0:
		return "—"
	if value_cp >= minimum_cp:
		return "✓"
	if value_cp * 2 >= minimum_cp:
		return "½"
	if value_cp * 4 >= minimum_cp:
		return "¼"
	return "!"


static func _garrison_min_per_family(territory_type: String) -> int:
	# Per `acore_axioms` §garrison and §classification_modifiers.
	match territory_type:
		"civilized":   return 2
		"borderlands": return 3
		"wilderness":  return 4
		_:             return 2


static func _garrison_per_family(domain: Dictionary) -> int:
	var peasants: int = int(domain.get("peasant_families", 0))
	if peasants <= 0:
		return 0
	# Phase 0 simplification: garrison_troops × 2gp universal min ÷ peasants.
	# Phase 5 surfaces a real per-unit aggregate.
	var troops: int = int(domain.get("garrison_troops", 0))
	if troops <= 0:
		return 0
	return (troops * 2) / peasants
