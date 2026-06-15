class_name SeedShareCodec
extends RefCounted

## Campaign-creation §9: seed-sharing tokens. A world is reproduced bit-identically
## by (campaign_seed + the full SettingParameters vector) — the pipeline's
## determinism guarantee. So a share token only needs to carry the seed plus the
## parameters that DIFFER from the defaults:
##   - default sliders  → the token is just the seed (e.g. "8675309")
##   - modified sliders → "<seed>~<base64(JSON of the changed fields)>"
## The delta is JSON (types preserved) so decode round-trips exactly through
## SettingParameters.from_dict(); base64 keeps the token copy-paste-safe.
##
## Pure logic, no scene dependency — headless-testable.

const _SEP := "~"


## Encode (seed, params) into a share token. Default params → bare seed.
static func encode(seed: int, params: SettingParameters) -> String:
	var deltas := _deltas(params)
	if deltas.is_empty():
		return str(seed)
	# sort_keys=true, full_precision=true — deterministic, lossless.
	return "%d%s%s" % [seed, _SEP, Marshalls.utf8_to_base64(JSON.stringify(deltas, "", true, true))]


## Decode a token into {ok, seed, params}. On any malformation, ok=false and
## params are the defaults (a safe fallback the UI can surface as "invalid token").
static func decode(token: String) -> Dictionary:
	var t := token.strip_edges()
	var sep := t.find(_SEP)
	var seed_str := t if sep < 0 else t.substr(0, sep)
	if not seed_str.is_valid_int():
		return {"ok": false, "seed": 0, "params": SettingParameters.new()}
	var seed := int(seed_str)
	if sep < 0:
		return {"ok": true, "seed": seed, "params": SettingParameters.new()}
	var json_str := Marshalls.base64_to_utf8(t.substr(sep + 1))
	if json_str == "":
		return {"ok": false, "seed": seed, "params": SettingParameters.new()}
	var deltas = JSON.parse_string(json_str)
	if not (deltas is Dictionary):
		return {"ok": false, "seed": seed, "params": SettingParameters.new()}
	return {"ok": true, "seed": seed, "params": SettingParameters.from_dict(deltas)}


## True when `params` matches the defaults (the seed alone is a complete share).
static func is_default(params: SettingParameters) -> bool:
	return _deltas(params).is_empty()


## The fields of `params` that differ from a fresh SettingParameters, in sorted
## key order (so the encoded token is stable for the same parameter set).
static func _deltas(params: SettingParameters) -> Dictionary:
	var defaults := SettingParameters.new().to_dict()
	var current := params.to_dict()
	var keys: Array = current.keys()
	keys.sort()
	var deltas := {}
	for k in keys:
		if current[k] != defaults.get(k):
			deltas[k] = current[k]
	return deltas
