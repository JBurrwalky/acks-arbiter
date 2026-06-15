class_name NarrativeGenerator
extends RefCounted

## Layer 7 (Stage 8): narrative synthesis (gdd-setting-generation.md §10).
##
## The narrative layer EXPLAINS what the generator already built — it never adds,
## moves, or invents a mechanical fact (§10.1/§10.3). Every block is a
## DETERMINISTIC template assembled from the persisted mechanical data; if and
## only if an LLM provider is configured (LLMManager.is_configured()) is a block
## upgraded IN PLACE to provider-authored prose (is_fallback → 0). With the mock
## provider OR no provider at all, the pipeline still yields a complete brief +
## timeline + per-entity blocks — "engine-first, LLM-second" (handoff §18).
##
## ZERO RNG: templates are pure functions of the mechanical data, so the §80
## determinism hash over setting_narrative is stable across runs.
##
## DEFERRED (no inputs yet — breadcrumbs so they slot in cleanly):
##  - Per-quest + per-rumor narration (§10.2): blocked on the NPC/quest system
##    (§9.8 is deferred), so there are no quest/rumor rows to narrate. Add a
##    `for q in ctx.get("sim_quests", [])` loop here when quests are seeded.
##  - Per-religion tradition (§10.2): needs culture `religion_hooks` (catalog
##    §3.4), not yet exposed by CultureCatalogLoader. Add `_religion_block(cid,
##    alignment)` per culture×alignment when that accessor lands.
##  - Region-name polish (top-8, handoff §78): an LLM-only upgrade of the Stage-5
##    deterministic region names; structurally it would call LLMManager per the
##    top significance-ranked region. Inert without a provider, so not built.

const _EVENT_TEMPLATES := {
	"war": "%s went to war with %s",
	"vassalage": "%s submitted to %s as a vassal",   # ids = [liege, vassal]
	"conquest": "%s conquered %s",
	"pillage": "%s pillaged the lands of %s",
	"secession": "%s broke away from %s",            # ids = [seceder, liege]
	"dynasty_change": "a new dynasty took the throne of %s",
	"collapse_rump": "%s fell into decline, shrinking back to its heartland",
	"collapse_shatter": "%s shattered into rival successor states",
	"depopulation": "%s collapsed, its lands emptying back into wilderness",
	"migration": "the %s folk migrated in search of new lands",  # uses culture, not polity
}

# Narration density per epoch (§10.2 — guidance, not invention).
const _DEEP_CUTOFF := 1500       # years-before-start ≥ this = deep history
const _MIDDLE_CUTOFF := 300      # this ≤ y < deep = middle history; y < this = near
const _DEEP_MAX := 12
const _MIDDLE_MAX := 18
const _NEAR_MAX := 14
const _REALM_HISTORY_MAX := 4    # recent-epoch events narrated per realm

var _polity_name: Dictionary = {}   # pol_id -> display name (alive realm, fallen reach, or generic)
var _events: Array = []             # parsed event dicts {y, type, polities, cultures, sig, id}


func run(ctx: Dictionary) -> bool:
	_index_polities(ctx)
	_index_events(ctx)

	var blocks: Array = []
	blocks.append(_timeline_block())
	for pol in ctx.get("sim_polities", []):
		blocks.append(_realm_block(pol))
	for cid in _cultures_present(ctx):
		blocks.append(_culture_block(cid))
	for r in ctx.get("sim_ruin_seeds", []):
		blocks.append(_dungeon_block(r))
	for p in ctx.get("sim_poi_seeds", []):
		blocks.append(_poi_block(p))
	blocks.append(_brief_block(ctx))
	# §9.8 quests / per-rumor / per-religion / region-polish: DEFERRED (see header).

	ctx["sim_narrative"] = blocks
	return true


# --- indexing ----------------------------------------------------------------

## pol_id → display name: alive realms use their Stage-5 name; fallen realms use
## "the Old <Toponym>"; anything else (a realm conquered without a fallen record)
## gets a generic label so a timeline line is never blank.
func _index_polities(ctx: Dictionary) -> void:
	_polity_name.clear()
	for pol in ctx.get("sim_polities", []):
		var nm := str(pol.get("name", "")).strip_edges()
		if nm == "":
			nm = "the realm of %s" % str(pol.get("id", "?"))
		_polity_name[str(pol.get("id", ""))] = nm
	for fp in ctx.get("sim_fallen_polities", []):
		var pid := str(fp.get("polity_id", ""))
		if not _polity_name.has(pid):
			var root := str(fp.get("toponym_root", "")).strip_edges()
			_polity_name[pid] = ("the Old %s" % root) if root != "" else "a vanished realm"


func _index_events(ctx: Dictionary) -> void:
	_events.clear()
	for e in ctx.get("sim_events", []):
		_events.append({
			"y": int(e.get("year_before_start", 0)),
			"type": str(e.get("type", "")),
			"polities": _parse_ids(e.get("polity_ids", "[]")),
			"cultures": _parse_ids(e.get("culture_ids", "[]")),
			"sig": float(e.get("significance", 0.0)),
			"id": str(e.get("id", "")),
		})


func _parse_ids(raw) -> Array:
	# Event id arrays are stored JSON-stringified (history_simulator._emit_event).
	if raw is Array:
		return raw
	var parsed = JSON.parse_string(str(raw))
	return parsed if parsed is Array else []


# --- blocks ------------------------------------------------------------------

func _timeline_block() -> Dictionary:
	var deep: Array = []
	var middle: Array = []
	var near: Array = []
	for e in _events:
		var y: int = e["y"]
		if y >= _DEEP_CUTOFF:
			deep.append(e)
		elif y >= _MIDDLE_CUTOFF:
			middle.append(e)
		else:
			near.append(e)
	var lines: Array = []
	lines.append("=== Deep history (4,000–1,500 years ago) ===")
	lines.append_array(_epoch_lines(deep, _DEEP_MAX))
	lines.append("")
	lines.append("=== Middle history (1,500–300 years ago) ===")
	lines.append_array(_epoch_lines(middle, _MIDDLE_MAX))
	lines.append("")
	lines.append("=== Near history (the last 300 years) ===")
	lines.append_array(_epoch_lines(near, _NEAR_MAX))
	return _wrap("timeline", "", "\n".join(lines),
		{"deep": deep.size(), "middle": middle.size(), "near": near.size()})


## Top-`limit` events of an epoch by significance, rendered as dated bullets.
## Deterministic order: significance DESC, then year DESC, then id ASC.
func _epoch_lines(events: Array, limit: int) -> Array:
	var sorted: Array = events.duplicate()
	sorted.sort_custom(func(a, b):
		if a["sig"] != b["sig"]:
			return a["sig"] > b["sig"]
		if a["y"] != b["y"]:
			return a["y"] > b["y"]
		return str(a["id"]) < str(b["id"]))
	var out: Array = []
	if sorted.is_empty():
		out.append("  (no recorded events in this age)")
		return out
	var n: int = mini(limit, sorted.size())
	for i in n:
		out.append("  ~%d years ago — %s." % [int(sorted[i]["y"]), _event_sentence(sorted[i])])
	return out


## Render one event as a sentence from its type + named actors. Never invents an
## event; only names what the simulation logged.
func _event_sentence(e: Dictionary) -> String:
	var type: String = e["type"]
	var tmpl := str(_EVENT_TEMPLATES.get(type, "%s endured a turn of fortune"))
	if type == "migration":
		var clabel := _culture_label(str(e["cultures"][0]) if e["cultures"].size() > 0 else "")
		return tmpl % clabel
	var a := _name_of(e["polities"], 0)
	if "%s" in tmpl and tmpl.count("%s") >= 2:
		return tmpl % [a, _name_of(e["polities"], 1)]
	return tmpl % a


func _name_of(ids: Array, idx: int) -> String:
	if idx >= ids.size():
		return "a neighbouring realm"
	return str(_polity_name.get(str(ids[idx]), "a vanished realm"))


func _realm_block(pol: Dictionary) -> Dictionary:
	var name := str(_polity_name.get(str(pol.get("id", "")), "this realm"))
	var title := str(pol.get("title", "realm"))
	var alignment := str(pol.get("alignment", "Neutral"))
	var rclass := str(pol.get("ruler_class", "ruler"))
	var rlevel := int(pol.get("ruler_level", 1))
	var rquality := str(pol.get("ruler_quality", "average"))
	var clan := str(pol.get("civ_or_clan_state", "civ"))
	var kind_word := "clanhold" if clan == "clan" else str(title).to_lower()
	var summary := "%s is a %s %s. Its throne is held by %s — a %s %s of the %d%s level." % [
		name, _align_word(alignment), kind_word, _ruler_phrase(rclass, rlevel),
		rquality, rclass, rlevel, _ordinal_suffix(rlevel)]

	# Recent history: this realm's near-epoch events, most significant first.
	var pid := str(pol.get("id", ""))
	var mine: Array = []
	for e in _events:
		if e["y"] < _MIDDLE_CUTOFF and _ids_has(e["polities"], pid):
			mine.append(e)
	mine.sort_custom(func(a, b):
		if a["sig"] != b["sig"]:
			return a["sig"] > b["sig"]
		return str(a["id"]) < str(b["id"]))
	var history := ""
	if mine.is_empty():
		history = " In living memory its affairs have been quiet."
	else:
		var parts: Array = []
		for i in mini(_REALM_HISTORY_MAX, mine.size()):
			parts.append(_event_sentence(mine[i]))
		history = " Within the last three centuries, " + _join_clauses(parts) + "."
	return _wrap("realm", pid, summary + history,
		{"name": name, "alignment": alignment, "ruler_class": rclass, "ruler_level": rlevel})


func _culture_block(cid: String) -> Dictionary:
	var rec := _culture_record(cid)
	var label := _culture_label(cid)
	var race := "people"
	var tendency := "varied"
	if not rec.is_empty():
		race = str(CultureCatalogLoader.race(rec))
		tendency = _dominant_sphere(CultureCatalogLoader.sphere_weights(rec))
	var body := "The %s are a %s people, inclined toward the %s sphere of influence. %s" % [
		label, race, tendency, _tendency_sentence(tendency)]
	return _wrap("culture", cid, body, {"culture_id": cid, "race": race, "tendency": tendency})


func _dungeon_block(r: Dictionary) -> Dictionary:
	var name := str(r.get("name", "a nameless ruin"))
	var dtype := str(r.get("dungeon_type", "ruin")).replace("_", " ")
	var size := str(r.get("size_hint", "lair"))
	var size_word := str({"large": "sprawling", "medium": "considerable", "small": "modest",
		"lair": "small"}.get(size, "modest"))
	var origin := ""
	var toponym := str(r.get("provenance_toponym", "")).strip_edges()
	if str(r.get("event_type", "")) == "geometric" or toponym == "":
		origin = "Its builders are forgotten, and few who enter return to tell of it."
	else:
		origin = "Raised in the age of the %s, it has since fallen to ruin and worse tenants." % toponym
	var body := "%s is a %s %s. %s" % [name, size_word, dtype, origin]
	return _wrap("dungeon", str(r.get("id", "")), body,
		{"dungeon_type": dtype, "size_hint": size, "toponym": toponym})


func _poi_block(p: Dictionary) -> Dictionary:
	var name := str(p.get("name", "an unmarked place"))
	var ptype := str(p.get("poi_type", "site")).replace("_", " ")
	var body := "%s is a %s." % [name, ptype]
	# First TRUE rumor seed becomes the local lore line (in NPC voice).
	var rumors = JSON.parse_string(str(p.get("rumor_seeds", "[]")))
	if rumors is Array and rumors.size() > 0:
		var hint := str(rumors[0].get("content_hint", "")).strip_edges()
		if hint != "":
			body += " Travellers whisper that %s" % _lower_first(hint)
			if not body.ends_with("."):
				body += "."
	return _wrap("poi", str(p.get("id", "")), body, {"poi_type": ptype})


func _brief_block(ctx: Dictionary) -> Dictionary:
	var realms: Array = ctx.get("sim_polities", [])
	var n_realms := realms.size()
	var cultures := _cultures_present(ctx)
	# The dominant realm: highest tier, then most recent founding (deterministic).
	var top = null
	for pol in realms:
		if top == null or _realm_rank(pol) > _realm_rank(top):
			top = pol
	var opening := "%d realms and clanholds contend across this land, peopled by %d cultures." % [
		n_realms, cultures.size()]
	var greatest := ""
	if top != null:
		greatest = " Foremost among them stands %s, a %s %s." % [
			str(_polity_name.get(str(top.get("id", "")), "a great power")),
			_align_word(str(top.get("alignment", "Neutral"))),
			str(top.get("title", "realm")).to_lower()]
	# Current tensions: the most significant near-epoch conflict.
	var tension := _current_tension()
	var brief := opening + greatest + tension \
		+ " Its deeper past is told in the chronicle of ages; what living folk remember shapes the quarrels of today."
	return _wrap("brief", "", brief, {"realms": n_realms, "cultures": cultures.size()})


# --- the provider wall -------------------------------------------------------

## Wrap a deterministic template as a narrative row. The template IS the output
## unless a configured provider returns usable prose (then is_fallback → 0). The
## context dict is what a real provider would receive; `fallback` lets it ground
## or skip. Never blocks: if unconfigured we never call out.
func _wrap(kind: String, subject_id: String, template_body: String, context: Dictionary) -> Dictionary:
	var body := template_body
	var is_fallback := 1
	if LLMManager.is_configured():
		var payload := context.duplicate()
		payload["task_type"] = kind
		payload["subject_id"] = subject_id
		payload["fallback"] = template_body
		var resp: ResponseEnvelope = LLMManager.request_narration(payload)
		if resp != null and resp.success and not resp.is_fallback \
				and resp.text.strip_edges() != "":
			body = resp.text
			is_fallback = 0
	var id := kind if subject_id == "" else "%s:%s" % [kind, subject_id]
	return {"id": id, "kind": kind, "subject_id": subject_id,
		"body": body, "is_fallback": is_fallback}


# --- helpers -----------------------------------------------------------------

func _cultures_present(ctx: Dictionary) -> Array:
	var seen := {}
	for pol in ctx.get("sim_polities", []):
		var cid := str(pol.get("culture_id", ""))
		if cid != "":
			seen[cid] = true
	var out: Array = seen.keys()
	out.sort()   # deterministic
	return out


func _culture_record(cid: String) -> Dictionary:
	var all := CultureCatalogLoader.load_all()
	return all.get(cid, {})


func _culture_label(cid: String) -> String:
	if cid == "":
		return "wandering"
	return cid.capitalize()


func _dominant_sphere(weights: Dictionary) -> String:
	var best := ""
	var best_w := -1.0
	var keys: Array = weights.keys()
	keys.sort()   # deterministic tiebreak
	for k in keys:
		if float(weights[k]) > best_w:
			best_w = float(weights[k])
			best = str(k)
	return best if best != "" else "balanced"


func _tendency_sentence(tendency: String) -> String:
	match tendency:
		"arcane":
			return "Their lore-keepers and mage-scholars are renowned."
		"divine":
			return "Their priesthoods hold great sway over daily life."
		"martial", "fighting":
			return "They prize martial prowess and the warrior's code."
		"trade", "mercantile":
			return "They are shrewd traders whose caravans range far."
	return "Their ways are shaped by generations on this land."


func _align_word(alignment: String) -> String:
	return alignment.to_lower()


func _ruler_phrase(rclass: String, _level: int) -> String:
	return "a %s" % rclass


func _ordinal_suffix(n: int) -> String:
	var m := n % 100
	if m >= 11 and m <= 13:
		return "th"
	match n % 10:
		1: return "st"
		2: return "nd"
		3: return "rd"
	return "th"


func _ids_has(ids: Array, target: String) -> bool:
	for i in ids:
		if str(i) == target:
			return true
	return false


func _join_clauses(parts: Array) -> String:
	if parts.size() == 1:
		return str(parts[0])
	if parts.size() == 2:
		return "%s, and %s" % [parts[0], parts[1]]
	var head: Array = parts.slice(0, parts.size() - 1)
	return "%s, and %s" % [", ".join(head), parts[parts.size() - 1]]


func _lower_first(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_lower() + s.substr(1)


## A coarse "importance" score for picking the setting's foremost realm.
func _realm_rank(pol: Dictionary) -> int:
	# tier dominates; founding_tick breaks ties (older realm = lower tick = wins).
	return int(pol.get("tier_index", 0)) * 100000 - int(pol.get("founded_tick", 0))


func _current_tension() -> String:
	var best = null
	for e in _events:
		if e["y"] >= _MIDDLE_CUTOFF:
			continue
		if e["type"] != "war" and e["type"] != "conquest":
			continue
		if best == null or e["sig"] > best["sig"] \
				or (e["sig"] == best["sig"] and str(e["id"]) < str(best["id"])):
			best = e
	if best == null:
		return " For now an uneasy peace holds."
	return " In recent years, %s." % _event_sentence(best)
