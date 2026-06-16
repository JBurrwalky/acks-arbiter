class_name NameAssembler
extends RefCounted

## Pure, deterministic runtime name composition from a static name bank
## (gdd-naming-conventions.md §4/§6.3/§7; region-painting §5.1). Layer 5 (Stage
## 6) calls these; every method is a function of (bank, rng, used) — no DB, no
## ctx, no global RNG — so it is trivially unit-testable and bit-reproducible.
##
## The caller supplies a per-entity RandomNumberGenerator from a WorldGenRng
## stream (so iteration order never affects a name) and a shared `used` dict
## ({culture_id: {name_lower: true}}) for per-culture dedup. On pool exhaustion
## a name is qualified (Upper/Lower/Great/Little, §5.6) until unique.

const _VOWELS := "aeiouyāēīōūáéíóúàèìòùâêîôûäëïöü'"
const _QUALIFIERS := ["Upper", "Lower", "Great", "Little", "Old", "New", "North", "South"]

## ACKS region subtype -> the lexicon feature-word key whose word heads the name
## (region-painting §5.1 subtype->recipe). An empty value means the subtype is
## inherently OPAQUE by design (continent — a top-significance proper name, §5.1)
## and falls through to the opaque `feature` pool; the same fallback also catches
## any subtype the kit lacks a word for.
const _SUBTYPE_FEATURE_KEY := {
	"range": "mountain", "forest": "forest", "desert": "desert", "plains": "plain",
	"plateau": "plain", "basin": "vale", "swamp": "marsh", "anomaly": "hill",
	"island": "isle", "major_isle": "isle", "archipelago": "isle", "cape": "cape",
	"bay": "bay", "gulf": "bay", "strait": "narrows", "peninsula": "cape",
	"isthmus": "neck", "ocean": "sea", "sea": "sea", "lake": "lake",
	"lakeland": "lake", "river": "river", "river_system": "river",
	"continent": "", "coast": "coast",
}


# --- core dedup-aware picker -------------------------------------------------

## Pick a not-yet-used name from `pool` (deterministically shuffled by `rng`),
## marking it used for `cid`. Qualifies (§5.6) when the pool is exhausted.
static func pick_unused(pool: Array, rng: RandomNumberGenerator,
		used: Dictionary, cid: String) -> String:
	var seen: Dictionary = used.get(cid, {})
	var order := _shuffled(pool, rng)
	for raw in order:
		var name := str(raw).strip_edges()
		if name.is_empty():
			continue
		if not seen.has(name.to_lower()):
			_mark(used, cid, name)
			return name
	# Exhausted — qualify the first candidate until unique.
	var base := ""
	for raw in order:
		base = str(raw).strip_edges()
		if not base.is_empty():
			break
	if base.is_empty():
		return ""
	for q in _QUALIFIERS:
		var cand := _apply_qualifier(q, base)
		if not seen.has(cand.to_lower()):
			_mark(used, cid, cand)
			return cand
	# Last resort: a Roman-numeral ordinal (deterministic, never collides), not a
	# bare base-10 counter.
	var n := 2
	var final := "%s %s" % [base, _roman(n)]
	while seen.has(final.to_lower()):
		n += 1
		final = "%s %s" % [base, _roman(n)]
	_mark(used, cid, final)
	return final


# --- name types --------------------------------------------------------------

## A settlement name. `grand` capitals prefer the flagship head of the pool
## (the authored great-city names lead `categories.settlement`).
static func settlement_name(bank: Dictionary, rng: RandomNumberGenerator,
		used: Dictionary, cid: String, grand: bool) -> String:
	var pool: Array = NameBankLoader.names(bank, "settlement")
	if grand and pool.size() > 0:
		# Bias toward the flagship head: try the first few in order first.
		var seen: Dictionary = used.get(cid, {})
		for i in range(min(6, pool.size())):
			var name := str(pool[i]).strip_edges()
			if not name.is_empty() and not seen.has(name.to_lower()):
				_mark(used, cid, name)
				return name
	if pool.is_empty():
		# Fall back to a feature-word compound (rare; e.g. a kit with no seeds).
		return feature_name(bank, "plains", rng, used, cid)
	return pick_unused(pool, rng, used, cid)


## A geographic/region feature name for an ACKS region subtype. Composes a
## subtype-matched transparent compound ([Adjective|Resource] + subtype-word)
## when the kit lexicon has the word; otherwise draws the opaque `feature` pool.
static func feature_name(bank: Dictionary, subtype: String,
		rng: RandomNumberGenerator, used: Dictionary, cid: String) -> String:
	var lex: Dictionary = bank.get("lexicon", {})
	var head_key: String = _SUBTYPE_FEATURE_KEY.get(subtype, "")
	var head := _lex_word(lex, "feature_words", head_key)
	var mods := _lex_values(lex, "adjectives") + _lex_values(lex, "resources")
	if not head.is_empty() and mods.size() > 0:
		# Deterministic transparent compound, deduped/qualified.
		var order := _shuffled(mods, rng)
		var seen: Dictionary = used.get(cid, {})
		for m in order:
			var name := compound(str(m), head)
			if not name.is_empty() and not seen.has(name.to_lower()):
				_mark(used, cid, name)
				return name
	# Opaque fallback: the pre-assembled feature pool.
	var pool: Array = NameBankLoader.names(bank, "feature")
	if pool.is_empty():
		pool = NameBankLoader.names(bank, "settlement")
	return pick_unused(pool, rng, used, cid)


## A noble-house / dynasty / horde name (distinct class from a common surname,
## §6.3) — drawn from the clan_house pool.
static func dynasty_name(bank: Dictionary, rng: RandomNumberGenerator,
		used: Dictionary, cid: String) -> String:
	var pool: Array = NameBankLoader.names(bank, "clan_house")
	if pool.is_empty():
		pool = NameBankLoader.names(bank, "personal_male")
	return pick_unused(pool, rng, used, cid)


## A realm name (§6.3): civ realms style the domain title over a root (capital /
## people-toponym / dynasty); beastman realms (no domain title) take the horde
## name. `tier_name` is the ACKS tier; roots may be "".
static func realm_name(bank: Dictionary, tier_name: String, toponym: String,
		capital_name: String, dynasty: String,
		rng: RandomNumberGenerator, used: Dictionary, cid: String) -> String:
	var domain := NameBankLoader.domain_title(bank, tier_name)
	# Beastman / scope-only ladders have no domain title — the horde IS the realm.
	if domain.is_empty():
		var horde := dynasty if not dynasty.is_empty() else capital_name
		if horde.is_empty():
			horde = toponym
		return _unique_literal(horde if not horde.is_empty()
			else "the %s Horde" % _safe(toponym, capital_name, "Wild"), used, cid)
	# Civ: build candidate roots most-distinctive first (capital, then dynasty
	# House, then the shared people-toponym). Return the first "<domain> of <root>"
	# not yet used — so same-culture realms vary by capital/House instead of piling
	# up identical "<domain> of <toponym>" that the dedup tail must number.
	var roots: Array = []
	if not capital_name.is_empty():
		roots.append(capital_name)
	if not dynasty.is_empty():
		roots.append("House %s" % dynasty)
	if not toponym.is_empty():
		roots.append(toponym)
	if roots.is_empty():
		roots.append(domain)
	var seen: Dictionary = used.get(cid, {})
	for r in roots:
		var cand := "%s of %s" % [domain, r]
		if not seen.has(cand.to_lower()):
			_mark(used, cid, cand)
			return cand
	# Every candidate root is taken → qualifier / Roman-numeral fallback.
	return _unique_literal("%s of %s" % [domain, str(roots[rng.randi() % roots.size()])], used, cid)


## A ruin/dungeon name (§9 adventure sites): "<size-styled site> of <toponym>".
static func ruin_name(bank: Dictionary, size_hint: String, toponym: String,
		rng: RandomNumberGenerator, used: Dictionary, cid: String) -> String:
	var site: String = _RUIN_SITE.get(size_hint, "Ruins")
	var root := toponym
	if root.is_empty():
		root = pick_unused(NameBankLoader.names(bank, "feature"), rng, used, cid)
	return _unique_literal("the %s of %s" % [site, root], used, cid)

const _RUIN_SITE := {
	"large": "Sunken Halls", "medium": "Lost Vaults",
	"small": "Old Catacombs", "lair": "Forgotten Warren",
}


## A road/highway name (§7 templates: "the [Toponym] Road/Way"). The generic
## road-word is transparent (English) so the route reads clearly on the map; the
## root carries the culture (a settlement name or the people's toponym).
static func road_name(root: String, rng: RandomNumberGenerator,
		used: Dictionary, cid: String) -> String:
	var generic: String = ["Road", "Way", "Path"][rng.randi() % 3]
	var base := root if not root.is_empty() else "Old"
	return _unique_literal("the %s %s" % [base, generic], used, cid)


## A ruler's styled title for narration (§6.1 rhyming ladder). Not persisted in
## Stage 6 (no ruler-name column) but provided for Stage 8 / tests.
static func ruler_styled_title(bank: Dictionary, tier_name: String, female: bool) -> String:
	var ruler := NameBankLoader.ruler_title(bank, tier_name)
	if female:
		var ff: Dictionary = NameBankLoader.titles(bank).get("female_forms", {})
		ruler = str(ff.get(ruler, ruler))
	return ruler


# --- compounding (mirrors tools/build_name_banks.py compound()) --------------

## Euphonic concatenation of two in-palette roots (the per-culture
## compounding_rule is authored prose, not executable, so a generic rule is
## used; identical to the Stage-5 build tool so runtime compounds match register).
static func compound(stem: String, head: String) -> String:
	var a := _first_token(stem).to_lower()
	var b := _first_token(head).to_lower()
	if a.is_empty() or b.is_empty():
		return ""
	if _is_vowel(a[a.length() - 1]) and _is_vowel(b[0]):
		a = a.substr(0, a.length() - 1)
	if not a.is_empty() and a[a.length() - 1] == b[0]:
		a = a.substr(0, a.length() - 1)
	return _titlecase(_collapse_runs(a + b))


# --- helpers -----------------------------------------------------------------

static func _shuffled(pool: Array, rng: RandomNumberGenerator) -> Array:
	var arr := pool.duplicate()
	# Fisher-Yates with the entity's deterministic rng.
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr


## Apply a §5.6 collision qualifier (Upper/Lower/Great/Little). When the name
## leads with an article ("the Red Maw"), the qualifier goes AFTER it ("the
## Upper Red Maw") rather than before ("Upper the Red Maw").
static func _apply_qualifier(q: String, name: String) -> String:
	for art in ["the ", "The "]:
		if name.begins_with(art):
			return "%s%s %s" % [art, q, name.substr(art.length())]
	return "%s %s" % [q, name]


static func _mark(used: Dictionary, cid: String, name: String) -> void:
	if not used.has(cid):
		used[cid] = {}
	used[cid][name.to_lower()] = true


static func _unique_literal(name: String, used: Dictionary, cid: String) -> String:
	var seen: Dictionary = used.get(cid, {})
	if name.is_empty():
		return ""
	if not seen.has(name.to_lower()):
		_mark(used, cid, name)
		return name
	for q in _QUALIFIERS:
		var cand := _apply_qualifier(q, name)
		if not seen.has(cand.to_lower()):
			_mark(used, cid, cand)
			return cand
	# Last resort: a Roman-numeral ordinal — a second identical title reads as a
	# legitimate successor realm ("… II"), never a meaningless base-10 counter.
	var n := 2
	var final := "%s %s" % [name, _roman(n)]
	while seen.has(final.to_lower()):
		n += 1
		final = "%s %s" % [name, _roman(n)]
	_mark(used, cid, final)
	return final


## Roman numeral for a small ordinal (same-name disambiguation suffix).
static func _roman(n: int) -> String:
	const VALS := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	const SYMS := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var out := ""
	var x := maxi(n, 1)
	for i in VALS.size():
		while x >= VALS[i]:
			out += SYMS[i]
			x -= VALS[i]
	return out


static func _lex_word(lex: Dictionary, group: String, key: String) -> String:
	if key.is_empty():
		return ""
	var words = lex.get(group, {})
	if typeof(words) == TYPE_DICTIONARY and words.has(key):
		return _first_token(str(words[key]))
	return ""


static func _lex_values(lex: Dictionary, group: String) -> Array:
	var out: Array = []
	var words = lex.get(group, {})
	if typeof(words) == TYPE_DICTIONARY:
		var keys: Array = words.keys()
		keys.sort()  # deterministic order before the rng shuffle
		for k in keys:
			var w := _first_token(str(words[k]))
			if not w.is_empty():
				out.append(w)
	return out


static func _first_token(s: String) -> String:
	var t := s.strip_edges()
	for sep in [" ", "/", ","]:
		var idx := t.find(sep)
		if idx >= 0:
			t = t.substr(0, idx)
	return t.strip_edges().lstrip("-").rstrip("-")


static func _is_vowel(ch: String) -> bool:
	return _VOWELS.find(ch) >= 0


static func _titlecase(w: String) -> String:
	if w.is_empty():
		return w
	return w.substr(0, 1).to_upper() + w.substr(1)


static func _collapse_runs(w: String) -> String:
	# Collapse any run of 3+ identical chars down to 2.
	var out := ""
	var run := 0
	var prev := ""
	for i in range(w.length()):
		var ch := w[i]
		if ch == prev:
			run += 1
		else:
			run = 1
			prev = ch
		if run <= 2:
			out += ch
	return out


static func _safe(a: String, b: String, c: String) -> String:
	if not a.is_empty():
		return a
	if not b.is_empty():
		return b
	return c
