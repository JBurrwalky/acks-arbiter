class_name CampaignCreationState
extends SessionState

## Hosts the pre-game setting-generation UI (the campaign-creation flow:
## gdd-campaign-creation-ui.md). Reached from campaign-select's "Generate New
## World". On approval the flow has already locked the world; we return to
## campaign select for now.
##
## The flow is a CanvasLayer added DIRECTLY to Main (not pushed onto the
## NavigationStack) — same as PartyCreationState — because the nav stack is still
## mid-transition from the campaign-select pop, so a push_node would be dropped.
##
## NOTE: the eventual route on `world_ready` is "party_creation" → play, but that
## needs the setting→runtime materialization (setting_* → runtime
## domains/settlements/realms), which is NOT built yet (see the
## project_setting_runtime_materialization memory). Until then a generated world
## is locked + browsable but not playable, so we land back on the menu.

var _flow: Node = null


func enter(runner, _context: Dictionary) -> void:
	var scene: PackedScene = preload(
		"res://scenes/ui/campaign_creation/campaign_creation_flow.tscn")
	_flow = scene.instantiate()
	_flow.campaign_ready.connect(
		func(campaign_id: String):
			runner.submit_action("world_ready", {"campaign_id": campaign_id})
	)
	runner.get_parent().add_child(_flow)


func exit(_runner) -> void:
	if _flow != null and is_instance_valid(_flow):
		_flow.queue_free()
	_flow = null


func handle_action(_runner, action: String, _payload: Dictionary) -> String:
	if action == "world_ready" or action == "cancel_creation":
		return "campaign_select"
	return ""
