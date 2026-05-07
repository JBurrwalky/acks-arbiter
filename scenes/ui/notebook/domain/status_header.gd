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
		return
	var name := String(domain.get("name", "Untitled Domain"))
	if name.is_empty():
		name = "Untitled Domain"
	var territory := String(domain.get("territory_type", "wilderness")).capitalize()
	if int(domain.get("is_chaotic_domain", 0)) == 1:
		territory += " · Chaotic"
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
	var stronghold_value := StrongholdRepository.get_stronghold_value_for_domain(domain_id)
	var stronghold_minimum := StrongholdRepository.classification_minimum_gp(territory_type, hex_count)
	var stronghold_glyph := _sufficiency_glyph(stronghold_value, stronghold_minimum)
	var garrison_per_fam: int = _garrison_per_family(domain)
	var garrison_min: int = _garrison_min_per_family(territory_type)
	var garrison_glyph := "✓" if garrison_per_fam >= garrison_min else "!"
	var treasury: int = int(domain.get("treasury_gp", 0))
	_row_operational.text = "Stronghold: %s/%s %s   Garrison: %dgp/fam %s   Treasury: %s" % [
		_format_count(stronghold_value), _format_count(stronghold_minimum),
		stronghold_glyph,
		garrison_per_fam, garrison_glyph,
		_format_count(treasury),
	]


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _format_count(n: int) -> String:
	if n >= 1000:
		return "%d,%03d" % [n / 1000, n % 1000]
	return str(n)


static func _sufficiency_glyph(value_gp: int, minimum_gp: int) -> String:
	if minimum_gp <= 0:
		return "—"
	if value_gp >= minimum_gp:
		return "✓"
	if value_gp * 2 >= minimum_gp:
		return "½"
	if value_gp * 4 >= minimum_gp:
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
