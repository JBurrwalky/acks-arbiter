extends Control

## Screen D: Review & Approval (gdd-campaign-creation-ui.md §6, setting-gen §11.3).
## Renders CampaignReviewAssembler's payload — the map + the four side tabs
## (Brief / Realms / Peoples / History) + the seed footer (SeedShareCodec token) —
## and offers Accept / Regenerate. SCAFFOLD: the map renderer + tab LAYOUT are an
## in-editor pass; the payload binding is authored here.

signal approved
signal regenerate_requested

var _payload: Dictionary = {}


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# EDITOR: the map renderer with overlay toggles (political realms / region names
	# / classification / dungeon-POI markers); a side overlay with Brief / Realms /
	# Peoples / History tabs bound to _payload; a footer with the copyable share
	# token, [Regenerate world] → regenerate_requested, [Regenerate element…] (the
	# §11.3 v1 constrained menu), and [Begin Campaign] (confirm modal stating the
	# post-approval lock → emit approved).
	pass


## Bind the assembled review struct (CampaignReviewAssembler.assemble). Keys:
## seed, world_hash, share_token, share_is_default, brief, timeline, realms[],
## peoples[], validation{ok,errors,warnings,report}.
func populate(payload: Dictionary) -> void:
	_payload = payload
	_refresh()


func _refresh() -> void:
	# EDITOR: bind _payload.brief / .timeline / .realms / .peoples / .validation /
	# .share_token onto the tabs + footer. A realm row click pans the map to its
	# capital (capital_q/capital_r); a history-event click highlights its hexes.
	pass


func share_token() -> String:
	return str(_payload.get("share_token", ""))
