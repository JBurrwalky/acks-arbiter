class_name CampaignReviewAssembler
extends RefCounted

## Campaign-creation §6 (Screen D: Review & Approval): compose the persisted
## generated world into the structured payload the review screen renders — the
## four side-overlay tabs (Brief / Realms / Peoples / History), the seed footer,
## and the §11.3 validation surface. Pure reader over the locked setting_* tables;
## the UI binds to the returned dict, it computes nothing itself.
##
## Headless-testable: returns a plain Dictionary, no scene dependency.


## { seed, world_hash, share_token, share_is_default, brief, timeline,
##   realms[], peoples[], validation }
static func assemble(campaign_id: String) -> Dictionary:
	var params_row := SettingRepository.get_parameters(campaign_id)
	var seed := int(params_row.get("campaign_seed", 0))
	var params := SettingParameters.from_dict(_parse_params(params_row))

	var narrative := _index_narrative(campaign_id)
	var polities := SettingRepository.list_polities(campaign_id)

	return {
		"seed": seed,
		"world_hash": str(params_row.get("world_hash", "")),
		"share_token": SeedShareCodec.encode(seed, params),
		"share_is_default": SeedShareCodec.is_default(params),
		"brief": str(narrative.get("brief", "")),
		"timeline": str(narrative.get("timeline", "")),
		"realms": _realms(polities, narrative),
		"peoples": _peoples(polities, narrative),
		"validation": _validation(campaign_id),
	}


static func _parse_params(params_row: Dictionary) -> Dictionary:
	var parsed = JSON.parse_string(str(params_row.get("params_json", "{}")))
	return parsed if parsed is Dictionary else {}


## kind/subject -> body, so a tab can pull its narrative block by key.
static func _index_narrative(campaign_id: String) -> Dictionary:
	var out := {}
	for n in SettingRepository.list_narrative(campaign_id):
		var key := str(n.get("kind", ""))
		if str(n.get("subject_id", "")) != "":
			key = "%s:%s" % [key, str(n.get("subject_id", ""))]
		out[key] = str(n.get("body", ""))
	return out


## Realms tab: every realm with the fields the list + map-pan need, the strongest
## first (tier DESC, then name) for a stable, sensible order.
static func _realms(polities: Array, narrative: Dictionary) -> Array:
	var out: Array = []
	for p in polities:
		out.append({
			"id": str(p.get("id", "")),
			"name": str(p.get("name", "")),
			"title": str(p.get("title", "")),
			"alignment": str(p.get("alignment", "")),
			"culture_id": str(p.get("culture_id", "")),
			"ruler_class": str(p.get("ruler_class", "")),
			"ruler_level": int(p.get("ruler_level", 0)),
			"tier_index": int(p.get("tier_index", 0)),
			"capital_q": int(p.get("capital_q", 0)),
			"capital_r": int(p.get("capital_r", 0)),
			"blurb": str(narrative.get("realm:%s" % str(p.get("id", "")), "")),
		})
	out.sort_custom(func(a, b):
		if int(a["tier_index"]) != int(b["tier_index"]):
			return int(a["tier_index"]) > int(b["tier_index"])
		return str(a["name"]) < str(b["name"]))
	return out


## Peoples tab: the distinct cultures present, each with its narrative blurb.
static func _peoples(polities: Array, narrative: Dictionary) -> Array:
	var seen := {}
	for p in polities:
		var cid := str(p.get("culture_id", ""))
		if cid != "":
			seen[cid] = true
	var ids: Array = seen.keys()
	ids.sort()
	var out: Array = []
	for cid in ids:
		out.append({
			"culture_id": cid,
			"label": cid.capitalize(),
			"blurb": str(narrative.get("culture:%s" % cid, "")),
		})
	return out


static func _validation(campaign_id: String) -> Dictionary:
	var result: Dictionary = SettingValidator.new().validate(campaign_id)
	return {
		"ok": bool(result.get("ok", false)),
		"errors": result.get("errors", []).size(),
		"warnings": result.get("warnings", []).size(),
		"report": str(result.get("report", "")),
	}
