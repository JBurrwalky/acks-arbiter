class_name ReplayFrameDecoder
extends RefCounted

## Campaign-creation §5/§7: decode a stored replay frame's RLE `owner_by_hex`
## back to per-hex ownership for the epoch-by-epoch playback. The encoding
## (history_simulator._rle_owners) is runs of "<polity>:<count>" joined by ';'
## over CANONICAL hex order (r ASC, q ASC) — the exact order
## SettingRepository.list_hexes returns. "" polity = unowned.
##
## Pure logic, no scene dependency — headless-testable.


## Expand the RLE into a flat Array of owner ids, one per hex in canonical order.
static func decode_runs(rle: String) -> Array:
	var out: Array = []
	if rle.strip_edges() == "":
		return out
	for run in rle.split(";", false):
		var colon := run.rfind(":")   # the count separator (polity ids carry no ':')
		if colon < 0:
			continue
		var owner := run.substr(0, colon)
		var count := int(run.substr(colon + 1))
		for i in count:
			out.append(owner)
	return out


## Zip the decoded runs against canonical-ordered hexes → {Vector2i -> owner_id},
## skipping unowned ('') hexes. `ordered_hexes` MUST be in list_hexes order.
static func decode_owner_map(rle: String, ordered_hexes: Array) -> Dictionary:
	var owners := decode_runs(rle)
	var out := {}
	var n: int = mini(owners.size(), ordered_hexes.size())
	for i in n:
		var owner: String = owners[i]
		if owner == "":
			continue
		var h = ordered_hexes[i]
		out[Vector2i(int(h["q"]), int(h["r"]))] = owner
	return out
