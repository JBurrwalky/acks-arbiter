class_name SettingValidator
extends RefCounted

## Layer 8 (Stage 9): the §11.1 mechanical validation checklist
## (gdd-setting-generation.md §11.1; handoff §9.2 — "data-driven checks with
## per-check IDs so failures cite themselves").
##
## Reads the PERSISTED setting_* data and returns a structured result. STRUCTURAL
## invariants that must always hold are ERRORS (a failing one means the world is
## broken); DISTRIBUTIONS that merely ought to fall in a range are WARNINGS (the
## §9.3 balance pass is Jedidiah's call, not a generation gate). The result feeds
## player review (§11.3); the post-approval LOCK itself is applied by the
## approval flow (SettingRepository.lock_setting), not here.
##
## Pure reader — never writes — so it has no determinism-hash footprint and can be
## re-run on demand by the review UI.

const _MARKET_I := 20000     # market-class thresholds by urban families
const _MARKET_II := 5000     # (acore-campaign-hijinks.xml:632-638; mirrors
const _MARKET_III := 1750    # InfrastructureGenerator._market_class — RAW-stable)
const _MARKET_IV := 600
const _MARKET_V := 250

const _WEIGHT_TOLERANCE := 0.02     # owned-hex substrate sum vs 1.0
const _WILD_LOW := 0.30             # wilderness-fraction warning band (§11.1 ~50%)
const _WILD_HIGH := 0.75


## Returns {ok, errors, warnings, report}. ok == errors.is_empty().
func validate(campaign_id: String) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []

	var hexes := SettingRepository.list_hexes(campaign_id)
	var polities := SettingRepository.list_polities(campaign_id)
	var settlements := SettingRepository.list_settlements(campaign_id)
	var roads := SettingRepository.list_roads(campaign_id)
	var ruins := SettingRepository.list_ruin_seeds(campaign_id)
	var events := SettingRepository.list_events(campaign_id)

	var grid := {}   # Vector2i -> hex row, for orphan/ownership lookups
	for h in hexes:
		grid[Vector2i(int(h["q"]), int(h["r"]))] = h

	_check_hexes(hexes, errors, warnings)                 # V1, V2, V4
	_check_wilderness_fraction(hexes, warnings)           # V5
	_check_settlements(settlements, grid, errors)         # V6, V13a
	_check_vassals(polities, errors, warnings)            # V8
	_check_rulers(polities, grid, errors, warnings)       # V9, V13b, V7
	_check_ruins(ruins, events, errors)                   # V11
	_check_roads(settlements, roads, warnings)            # V12

	var ok: bool = errors.is_empty()
	return {
		"ok": ok, "errors": errors, "warnings": warnings,
		"report": _format_report(campaign_id, ok, errors, warnings),
	}


# --- checks ------------------------------------------------------------------

## V1 hex completeness, V2 substrate normalization, V4 limits-of-growth caps.
func _check_hexes(hexes: Array, errors: Array, warnings: Array) -> void:
	var c := SimConstants.new()
	var classes := ["wilderness", "borderlands", "civilized"]
	var weight_off := 0
	for h in hexes:
		var q := int(h["q"])
		var r := int(h["r"])
		var water := str(h.get("water", ""))
		# V1: land hexes carry physical fields + a valid class; water hexes only need
		# a valid water tag (biome/class/substrate are land concepts).
		if water == "":
			if str(h.get("elevation", "")) == "" or str(h.get("biome", "")) == "":
				_err(errors, "V1", "land hex (%d,%d) missing elevation/biome" % [q, r])
			var tc := str(h.get("territory_class", ""))
			if not (tc in classes):
				_err(errors, "V1", "land hex (%d,%d) has invalid territory_class '%s'" % [q, r, tc])
			# V4: population never exceeds the class cap (limits-of-growth).
			var pop := int(h.get("population_band", 0))
			var cap: int = c.cap_for(tc) if tc in classes else c.cap_wilderness
			if pop > cap:
				_err(errors, "V4", "hex (%d,%d) population %d exceeds the %s cap %d" % [q, r, pop, tc, cap])
			# V2: an OWNED hex must carry a normalized substrate (~1.0). Unowned land
			# legitimately carries only an un-normalized trader-floor trace, so it is
			# skipped (history-sim §11.1 serialize note).
			if str(h.get("owner_polity_id", "")) != "":
				var w = JSON.parse_string(str(h.get("culture_weights", "{}")))
				if not (w is Dictionary) or w.is_empty():
					_err(errors, "V2", "owned hex (%d,%d) has no culture substrate" % [q, r])
				else:
					var sum := 0.0
					for k in w:
						sum += float(w[k])
					if absf(sum - 1.0) > _WEIGHT_TOLERANCE:
						weight_off += 1
		else:
			if not (water in ["ocean", "lake"]):
				_err(errors, "V1", "water hex (%d,%d) has invalid water tag '%s'" % [q, r, water])
	if weight_off > 0:
		_warn(warnings, "V2", "%d owned hexes have a substrate sum off 1.0 by > %.2f" % [weight_off, _WEIGHT_TOLERANCE])


## V5 map-wide wilderness fraction (~50% target; a band, not a gate).
func _check_wilderness_fraction(hexes: Array, warnings: Array) -> void:
	var land := 0
	var wild := 0
	for h in hexes:
		if str(h.get("water", "")) != "":
			continue
		land += 1
		if str(h.get("territory_class", "")) == "wilderness":
			wild += 1
	if land == 0:
		_warn(warnings, "V5", "no land hexes")
		return
	var frac := float(wild) / float(land)
	if frac < _WILD_LOW or frac > _WILD_HIGH:
		_warn(warnings, "V5", "wilderness fraction %.0f%% is outside the ~50%% band (%d/%d land hexes)"
			% [frac * 100.0, wild, land])


## V6 market class consistent with urban families; V13a settlement on a real hex.
func _check_settlements(settlements: Array, grid: Dictionary, errors: Array) -> void:
	for s in settlements:
		var sid := str(s.get("id", "?"))
		var fam := int(s.get("urban_families", 0))
		var mc := int(s.get("market_class", 0))
		if mc != _market_class(fam):
			_err(errors, "V6", "settlement %s market_class %d != table value for %d families" % [sid, mc, fam])
		var key := Vector2i(int(s["hex_q"]), int(s["hex_r"]))
		if not grid.has(key):
			_err(errors, "V13", "settlement %s sits on a non-existent hex (%d,%d)" % [sid, key.x, key.y])


## V8 vassal chains: a set liege is not the polity itself (ERROR) and forms no
## cycle (ERROR). A liege that no longer exists (its realm fell) is a WARNING — the
## vassal is effectively independent, a tolerable present-day state.
func _check_vassals(polities: Array, errors: Array, warnings: Array) -> void:
	var liege_of := {}
	var ids := {}
	for p in polities:
		ids[str(p["id"])] = true
	for p in polities:
		var pid := str(p["id"])
		var liege := str(p.get("liege_id", ""))
		if liege == "":
			continue
		if liege == pid:
			_err(errors, "V8", "polity %s is its own liege" % pid)
			continue
		if not ids.has(liege):
			_warn(warnings, "V8", "polity %s has a liege %s whose realm has fallen" % [pid, liege])
			continue
		liege_of[pid] = liege
	# Cycle detection over the liege edges.
	for start in liege_of:
		var seen := {}
		var cur: String = start
		while liege_of.has(cur):
			if seen.has(cur):
				_err(errors, "V8", "vassal chain through %s forms a cycle" % start)
				break
			seen[cur] = true
			cur = str(liege_of[cur])


## V9 morale seed present + parseable; V13b capital on a real hex; V7 tier sanity.
func _check_rulers(polities: Array, grid: Dictionary, errors: Array, warnings: Array) -> void:
	var hex_count := {}
	for key in grid:
		var owner := str(grid[key].get("owner_polity_id", ""))
		if owner != "":
			hex_count[owner] = int(hex_count.get(owner, 0)) + 1
	# V7 judges tier against the WHOLE realm (own + transitive war-vassals), matching the
	# realm-tier that now sets the title (§7.4e / §12) — a king ruling vassal-duchies has
	# few own hexes but a large realm, which is plausible, not a warning.
	var vassals_of := {}
	for p in polities:
		var lg := str(p.get("liege_id", ""))
		if lg != "":
			if not vassals_of.has(lg):
				vassals_of[lg] = []
			vassals_of[lg].append(str(p["id"]))
	for p in polities:
		var pid := str(p["id"])
		# V9: seeded morale present (Stage 4g §12.2) and valid JSON.
		var morale = JSON.parse_string(str(p.get("morale_seed", "")))
		if not (morale is Array or morale is Dictionary):
			_err(errors, "V9", "polity %s has an unparseable morale_seed" % pid)
		# V13b: capital coordinate is a real grid hex.
		var cap := Vector2i(int(p.get("capital_q", 0)), int(p.get("capital_r", 0)))
		if not grid.has(cap):
			_err(errors, "V13", "polity %s capital (%d,%d) is not a real hex" % [pid, cap.x, cap.y])
		# V7: a high tier on a one-hex holding is implausible (an empire can't be 3
		# hexes — §12.1). A warning: the present-day handoff is the authority.
		var tier := int(p.get("tier_index", 0))
		var held := _realm_hex_count(pid, vassals_of, hex_count, {})
		if tier >= 5 and held < 4:
			_warn(warnings, "V7", "polity %s is tier %d but its whole realm holds only %d hexes" % [pid, tier, held])


## Own hexes plus every transitive war-vassal's hexes (visited-set guarded against any
## stray liege cycle, which V8 reports separately).
func _realm_hex_count(pid: String, vassals_of: Dictionary, hex_count: Dictionary, seen: Dictionary) -> int:
	if seen.has(pid):
		return 0
	seen[pid] = true
	var total := int(hex_count.get(pid, 0))
	for vid in vassals_of.get(pid, []):
		total += _realm_hex_count(str(vid), vassals_of, hex_count, seen)
	return total


## V11 every NON-geometric ruin seed carries real provenance. A sim ruin's
## provenance is its fallen realm's culture / polity / era (history_simulator
## `_emit_ruin`); it does NOT store a source_event_id FK, so that link is only
## validated when actually set (future-proofing). Geometric top-ups are exempt.
func _check_ruins(ruins: Array, events: Array, errors: Array) -> void:
	var event_ids := {}
	for e in events:
		event_ids[str(e["id"])] = true
	for r in ruins:
		if str(r.get("event_type", "")) == "geometric":
			continue   # geometric top-ups carry no provenance by design (§9.3)
		var rid := str(r.get("id", "?"))
		if str(r.get("provenance_culture_id", "")) == "":
			_err(errors, "V11", "non-geometric ruin %s has no provenance culture" % rid)
		var src := str(r.get("source_event_id", ""))
		if src != "" and not event_ids.has(src):
			_err(errors, "V11", "ruin %s source_event_id '%s' does not resolve to a logged event"
				% [rid, src])


## V12 a realm with >= 2 mapped settlements ought to have a connecting road. A
## WARNING, not an error: disjoint terrain can make a realm's settlements
## genuinely unreachable by dry land. (Promote if road coverage is guaranteed.)
func _check_roads(settlements: Array, roads: Array, warnings: Array) -> void:
	var pol_of := {}
	var settle_count := {}
	for s in settlements:
		var pol := str(s.get("polity_id", ""))
		pol_of[str(s.get("id", ""))] = pol
		settle_count[pol] = int(settle_count.get(pol, 0)) + 1
	var roaded_polity := {}
	for r in roads:
		roaded_polity[str(pol_of.get(str(r.get("from_settlement_id", "")), ""))] = true
		roaded_polity[str(pol_of.get(str(r.get("to_settlement_id", "")), ""))] = true
	var unroaded := 0
	for pol in settle_count:
		if int(settle_count[pol]) >= 2 and not roaded_polity.has(pol):
			unroaded += 1
	if unroaded > 0:
		_warn(warnings, "V12", "%d realm(s) with >=2 settlements have no connecting road" % unroaded)


# --- helpers -----------------------------------------------------------------

func _market_class(fam: int) -> int:
	if fam >= _MARKET_I: return 1
	if fam >= _MARKET_II: return 2
	if fam >= _MARKET_III: return 3
	if fam >= _MARKET_IV: return 4
	if fam >= _MARKET_V: return 5
	return 6


func _err(errors: Array, id: String, msg: String) -> void:
	errors.append({"id": id, "severity": "error", "message": msg})


func _warn(warnings: Array, id: String, msg: String) -> void:
	warnings.append({"id": id, "severity": "warning", "message": msg})


func _format_report(campaign_id: String, ok: bool, errors: Array, warnings: Array) -> String:
	var lines: Array = []
	lines.append("Setting validation — campaign %s: %s" % [campaign_id, "PASS" if ok else "FAIL"])
	lines.append("  %d error(s), %d warning(s)" % [errors.size(), warnings.size()])
	for e in errors:
		lines.append("  [ERROR %s] %s" % [str(e["id"]), str(e["message"])])
	for w in warnings:
		lines.append("  [warn  %s] %s" % [str(w["id"]), str(w["message"])])
	return "\n".join(lines)
